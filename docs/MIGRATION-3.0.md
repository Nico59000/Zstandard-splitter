# Migration from 3.0

The local command line remains compatible. Network publication adds `-P`, `-G`, `-Q`, `-R`, `-O`, and `-F`; version 4.2 also enables `-Y`.

Strict network transfers use the existing version 3 manifest format. No manifest conversion is required.

The 4.x source also fixes the recursive source-inventory walker: recursive calls execute in a subshell so POSIX-shell global variables cannot alter the relative path used for later sibling entries. Existing manifests should be regenerated before archival use when they were created from directory trees containing sibling directories after regular files.
