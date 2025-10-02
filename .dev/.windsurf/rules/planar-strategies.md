---
trigger: glob
description:
globs: user/strategies/**/*.jl
---
When editing strategies, remember that the main entry point is the function with signature:

`function call!(s::SC, ts::DateTime, _)`

When adding optimization functions remember to import the optimization environment (macro `@optenv!`)