# System Prompt Slimming - Handoff Document

## Goal
Reduce Claude Code's system prompt by ~45% (currently at 11%, need ~34% more).

## Current Progress

### What's Been Done
- **Backup/restore system**: `backup-cli.sh` and `restore-cli.sh` with SHA256 verification
- **Patch system**: `patch-cli.js` that restores from backup then applies patches (idempotent)
- **3 patches applied**, saving 11.3% (~6KB, 107 lines):
  1. Removed duplicate emoji instruction from Edit tool
  2. Removed duplicate emoji instruction from Write tool
  3. Slimmed TodoWrite examples from 8 verbose to 2 concise

### What Worked
- **File-based patches**: Large find/replace strings stored in `patches/*.find.txt` and `patches/*.replace.txt`
- **Inline patches**: Small patches can be defined directly in `patch-cli.js`
- **Extraction verification**: Use `CLI_PATH=/path/to/cli.js node extract-system-prompt.js output.md` to verify changes

### What Didn't Work
- **Template literals for large strings**: Embedding 6KB strings in JS template literals caused matching issues (whitespace/encoding differences)
- **Solution**: Load large patches from external `.txt` files instead

## Remaining Tasks (~34% more savings needed)

### 1. EnterPlanMode examples (~73 lines, ~9%)
Current location in extracted prompt: lines 743-816
- Has 6 examples (3 "good", 3 "bad")
- Reduce to 2 examples (1 good, 1 bad)

To create this patch:
```bash
# Extract the section from backup
node -e "
const fs = require('fs');
const content = fs.readFileSync('$HOME/.claude/local/node_modules/@anthropic-ai/claude-code/cli.js.backup', 'utf8');
const start = content.indexOf('## When to Use This Tool');
const end = content.indexOf('## Important Notes');
// Find the examples subsection and save to file
"
```

### 2. Parallel tools repetition (~25 lines, ~3%)
The phrase "You can call multiple tools in a single response" appears 6 times. Keep the main one in Tool Usage Policy, remove from:
- Git commit section (lines 158, 167)
- PR creation section (lines 199, 205)
- Glob tool section (line 368)

These are small inline patches - add directly to `patch-cli.js`.

### 3. Code References section (~12 lines, ~1.5%)
Remove entirely - lines 232-239 in extracted prompt. The model naturally does this.

Find: `# Code References\n\nWhen referencing...` through the example.
Replace: empty string

### 4. Git commit section simplification (~30 lines, ~4%)
Current section has step-by-step hand-holding. Keep:
- Safety rules (never force push, etc.)
- HEREDOC format example
Remove:
- Verbose step numbering
- Repeated "call multiple tools" instructions

### 5. PR creation section simplification (~20 lines, ~2.5%)
Similar to git commit - keep format template, remove verbose steps.

## How to Add a New Patch

### For small patches (inline):
```javascript
// In patch-cli.js, add to patches array:
{
  name: 'Description of patch',
  find: `exact string to find`,
  replace: `replacement string`
}
```

### For large patches (file-based):
1. Create `patches/patch-name.find.txt` with exact text to find
2. Create `patches/patch-name.replace.txt` with replacement
3. Add to patches array: `{ name: 'Description', file: 'patch-name' }`

**Important**: The find text must match EXACTLY, including whitespace and newlines.

## Important: Iterate and Test

**Do NOT try to add all patches at once.** Work iteratively:

1. Add ONE patch
2. Run the patch script
3. Verify it applied (check "Patches applied: X/Y" output)
4. Run extraction to confirm the change looks correct
5. Commit
6. Move to next patch

If a patch shows `[SKIP]`, the find string doesn't match exactly. Debug by:
- Checking for whitespace differences
- Using `JSON.stringify()` to compare strings byte-by-byte
- For large patches, use file-based approach instead of inline

## Testing Workflow

```bash
# 1. Setup test environment
mkdir -p /tmp/cli-test
cp ~/.claude/local/node_modules/@anthropic-ai/claude-code/cli.js /tmp/cli-test/cli.js
./backup-cli.sh /tmp/cli-test/cli.js

# 2. Run patches
node patch-cli.js /tmp/cli-test/cli.js

# 3. Verify with extraction
CLI_PATH=/tmp/cli-test/cli.js node extract-system-prompt.js /tmp/cli-test/patched.md

# 4. Compare
wc -l /tmp/cli-test/patched.md  # Should show fewer lines
grep -c "pattern" /tmp/cli-test/patched.md  # Verify specific changes

# 5. Cleanup
rm -rf /tmp/cli-test
```

## File Structure
```
experiments/system-prompt-extraction/
├── backup-cli.sh              # Creates verified backup
├── restore-cli.sh             # Restores from backup
├── patch-cli.js               # Applies all patches (idempotent)
├── extract-system-prompt.js   # Extracts prompt for verification
├── patches/
│   ├── todowrite-examples.find.txt
│   └── todowrite-examples.replace.txt
├── system-prompt.md           # Reference extracted prompt (original)
└── README.md                  # Overview
```

## Key Numbers
- Original prompt: 830 lines, 52,590 chars
- Current (after 3 patches): 723 lines, 46,615 chars
- Target (~45% reduction): ~457 lines, ~29,000 chars
- Still need to save: ~266 lines, ~17,600 chars
