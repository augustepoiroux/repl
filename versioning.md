# Stacked Git

1. Duplicate last version branch

```bash
git checkout <branch>
stg branch -C <new_branch>
```

2. Use stacked git to add a new (empty) commit

```bash
stg pop -a
stg new <new_commit>
```

3. Edit the commit message by writing the version number (using vim)

Inside vim, do

- Got to last line, end of line: `G$`
- Insert a new line: `o`
- Write the new commit message, then `Esc`
- Save and exit: `:wq`

4. Rebase the new branch on master

```bash
stg rebase master
```

5. Update the previous commit by reverting changes in master

```bash
stg push
git revert --no-commit <commit_id>
```

6. Check changes, keep only changes related to version change to propagate back all new features and bug fixes, then run tests

```bash
./test.sh
```

7. If the tests pass, add the changes

```bash
stg refresh
git revert --abort
```

Redo step 5. for as many missing versions as needed.

8. Push all commits

```bash
stg push -a
```

9. If successful, run tests

```bash
rm -rf ./.lake
rm -rf ./test/Mathlib/.lake
./test.sh
```

10. Push the new branch

```bash
./push_commits_one_by_one.sh
```
