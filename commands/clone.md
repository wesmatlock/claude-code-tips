# Clone Current Conversation

Clone the current conversation so it can be resumed as a branch.

## Instructions

Follow these steps to clone the current session:

1. Run `pwd` to get the current working directory

2. Convert the path to the encoded format by replacing all `/` with `-`
   Example: `/Users/yk/projects/foo` becomes `-Users-yk-projects-foo`

3. List the sessions directory to find the current session (exclude agent-* files):
   ```
   ls -lt ~/.claude/projects/[ENCODED_PATH]/*.jsonl | grep -v agent- | head -5
   ```
   The most recently modified `.jsonl` file (that's not an agent) is the current session.

4. Generate a new UUID:
   ```
   uuidgen | tr '[:upper:]' '[:lower:]'
   ```

5. Copy the session file to the new UUID:
   ```
   cp ~/.claude/projects/[ENCODED_PATH]/[CURRENT_SESSION].jsonl ~/.claude/projects/[ENCODED_PATH]/[NEW_UUID].jsonl
   ```

6. Set the clone's timestamp to 1 minute in the future so it becomes the "latest":
   ```
   touch -t [FUTURE_TIMESTAMP] ~/.claude/projects/[ENCODED_PATH]/[NEW_UUID].jsonl
   ```
   Generate FUTURE_TIMESTAMP with: `date -v+1M "+%Y%m%d%H%M.%S"`

7. Tell the user: "Session cloned to [NEW_UUID]. Exit and run `claude -c` to continue the branched conversation."
