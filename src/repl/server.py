import gc
import json
import os
from copy import deepcopy
from time import sleep

import pexpect
import psutil

from repl import REPL_DIR, __console


class LeanServer:
    # Inspired from: https://github.com/zhangir-azerbayev/repl/blob/bddf452deda0df2240b248e651bcc37fb8e59d01/pylean/pylean/__init__.py
    def __init__(self):
        self.proc = None
        self.start()

    def start(self):
        os.chdir(REPL_DIR)
        self.proc = pexpect.spawn("lake exe repl", cwd=REPL_DIR, encoding="utf-8")
        self.env_cache = {}

    def kill(self):
        self.proc.terminate(force=True)

    def restart(self):
        gc.collect()
        self.kill()
        self.start()
        gc.collect()

    def __del__(self):
        self.kill()

    def _process_request(self, dict_query: dict, verbose=False, timeout: int = 20):
        json_query = json.dumps(dict_query, ensure_ascii=False)
        if verbose:
            __console.print(json_query)

        self.proc.sendline(json_query)
        self.proc.expect_exact(json_query + "\r\n")
        self.proc.sendline()
        self.proc.expect_exact("\r\n")

        try:
            _ = self.proc.expect_exact("\r\n\r\n", timeout=timeout)
        except Exception as e:
            raise Exception(f"Uncaught exception: {e}")

        # clean up the output
        output = self.proc.before
        output = output.replace("\r\n", "\n")
        # this removes a few infos given by the Lean server when building the environment
        output = output[output.rfind("\r") + 1 :]
        if verbose:
            __console.print(output)

        parsed_output = json.loads(output)
        if "env" in parsed_output and "cmd" in dict_query:
            self.env_cache[dict_query["cmd"]] = parsed_output["env"]

        return parsed_output

    def run_file(
        self,
        path: str | None,
        save_env: bool = False,
        verbose: bool = False,
        timeout: int = 20,
    ):
        if not path:
            raise ValueError("`path` cannot be `None` or empty")
        return self._process_request(dict(path=path, saveEnv=save_env), verbose, timeout)

    def run_code(
        self,
        code: str | None,
        env: int | None = None,
        save_env: bool = False,
        verbose: bool = False,
        timeout: int = 20,
        auto_env_cache: bool = False,
    ):
        """
        Run a Lean code snippet and return the Lean REPL output.
        Args:
            code: The Lean code to run.
            env: The environment to use.
            verbose: Whether to print additional information during the verification process.
            timeout: The timeout for the request.
            auto_env_cache: Whether to automatically try to use previously cached environments when possible. Used for performance optimization purposes and only if `env` parameter is `None`.
        Returns:
            The output of the Lean server.
        """

        if code is None or code == "":
            raise ValueError("`code` cannot be `None` or empty")

        if env is None and auto_env_cache:
            # check if one of the cached environments can be used, i.e. is a prefix of the current code
            # we try to find the longest prefix first
            cached_codes = sorted(self.env_cache.keys(), key=len, reverse=True)
            for cached_code in cached_codes:
                if code.startswith(cached_code):
                    env = self.env_cache[cached_code]
                    code = code[len(cached_code) :]
                    if verbose:
                        __console.log(f"Using cached environment ({env=}): {cached_code}")
                    break

        command = dict(cmd=code, saveEnv=save_env) | (dict(env=env) if env is not None else {})
        return self._process_request(command, verbose, timeout)


class RobustLeanServer(LeanServer):
    """
    A Lean server that automatically restarts when it runs out of memory. It also manages the environment cache to support this feature.
    Cached environments indexes are negative integers starting from -1 to not conflict with the positive integers used by the Lean server.
    """

    def __init__(self):
        super().__init__()
        self.env_counter = 0
        self.env_cache = {}

    def _cache_to_lean_env(self, env: int | None):
        if env is None:
            return None
        if env >= 0:
            return env
        return self.env_cache[env]["repl_env"]

    def restart(self):
        super().restart()

        # re-cache all the environments
        for env_id, env_data in self.env_cache.items():
            self.env_cache[env_id]["repl_env"] = self.run_code(
                env_data["code"], env=self._cache_to_lean_env(env_data["depends_on"])
            )["env"]

    def get_env_cache(self, code: str, env: int | None = None) -> int:
        """
        Add a code snippet to the environment cache if this code snippet is not already in the cache.
        Args:
            code: The Lean code to cache.
            env: An environment on which this new environment depends. It must be in the cache.
        """
        # check if the code is already in the cache
        for cached_env, cached_data in self.env_cache.items():
            if cached_data["code"] == code:
                return cached_env

        if env and env >= 0:
            raise ValueError("`env` must be a negative integer to be used as an environment cache index.")

        # otherwise, add the code to the cache
        self.env_counter -= 1
        res = self.run_code(code, env=self._cache_to_lean_env(env), auto_env_cache=True)
        self.env_cache[self.env_counter] = {"code": code, "repl_env": res["env"], "depends_on": env}
        return self.env_counter

    def remove_env_cache(self, env_id: int):
        """
        Remove an environment from the cache and all environments that depend on it.
        Args:
            env_id: The environment id to remove.
        """
        self.env_cache.pop(env_id, None)
        for cached_env, cached_data in self.env_cache.items():
            if cached_data["depends_on"] == env_id:
                self.remove_env_cache(cached_env)

    def clear_cache(self, force: bool = False):
        """
        Clear the environment cache.
        Args:
            force: Whether to directly clear the memory cache. `force=False` will only clear the cache the next time the server runs out of memory.
        """
        self.env_cache = {}
        if force:
            self.restart()

    def _process_request(self, dict_query: dict, verbose=False, timeout: int = 20):
        restart_counter = 0
        while psutil.virtual_memory().percent > 80:
            if restart_counter > 5:
                raise Exception("Memory usage is too high. Restarting the Lean server did not help.")
            if verbose:
                __console.log("Memory usage is too high. Reloading the Lean server...")
            self.restart()
            sleep(1)
            restart_counter += 1

        # Manage indexes for the environment cache
        if "env" in dict_query and dict_query["env"] < 0:
            dict_query = deepcopy(dict_query)
            dict_query["env"] = self._cache_to_lean_env(dict_query["env"])

        return super()._process_request(dict_query, verbose, timeout)
