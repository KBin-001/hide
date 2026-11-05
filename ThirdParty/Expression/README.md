# Expression

Upstream: https://github.com/nicklockwood/Expression

Pinned commit: e9a9623aa5a0709179a6cd1cb3697f90aa8bdafd (source header version 0.13.9).

License: MIT, copyright Nick Lockwood. See LICENSE.md; license is also bundled as ThirdPartyNotices.txt. The original Expression.swift file is vendored unmodified under the core sources, so builds need no package network resolution. Only the numeric evaluator is included; AnyExpression is not needed.

The calculator's arithmetic delegates to NumericExpression using numeric constants. The local adapter retains button-entry state, formatting, and the separate PIN candidate; PIN strings are never sent to the expression parser.
