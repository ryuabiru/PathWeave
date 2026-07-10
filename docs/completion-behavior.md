# Completion Behavior

MVP behavior:

1. User types a command argument such as `inbox`
2. User presses `Ctrl+Space`
3. PowerShell extracts the current token near the cursor
4. The module runs `pwv search --format json`
5. Results are shown through PowerShell selection UI
6. The chosen path is quoted when necessary and inserted back into the buffer

Future `Tab` integration should only run after standard completion returns no candidates.
