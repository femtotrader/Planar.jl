---
trigger: glob
description:
globs: test*.jl
---
# Planar.jl Test Rules

## Test Structure and Organization

### Test Location
- **All tests must be placed in `PlanarDev/test/` directory**
- Tests should be organized by functionality and follow the existing naming convention
- Each test file should be named `test_<functionality>.jl`

### Test File Structure
```julia
using PlanarDev.Stubs
using Test
using .Planar.Engine.Simulations: Simulations as sml
using .Planar.Engine.Data: Data as da
using .Planar.Engine.Strategies: Strategies as st
using .Planar.Engine.Executors: Executors as ex
using .Planar.Engine.Misc: Misc as ms
using .Planar.Engine.Lang: Lang as lg

function test_<functionality>()
    @eval begin
        using PlanarDev.Planar.Engine: Engine as egn
        using .egn.Strategies: Strategies as st
        using .egn.Executors: Executors as ex
        using .egn.Data: Data as da
        using .egn.Misc: Misc as ms
        using .egn.Simulations: Simulations as sml
        PlanarDev.@environment!
    end
    
    # Test implementation here
end
```

### Test Registration
- **All tests must be registered in `PlanarDev/test/runtests.jl`**
- Add test name to the `all_tests` array in alphabetical order
- Follow the existing pattern: `:test_name` (without the `test_` prefix)

## Test Execution

### Running Individual Tests
```bash
# From the project root directory
julia --startup-file=no --project=PlanarDev/test/ PlanarDev/test/runtests.jl <test_name>
```

### Running All Tests
```bash
# From the project root directory
julia --startup-file=no --project=PlanarDev/test/ PlanarDev/test/runtests.jl
```

### Environment Setup
- Tests use the `PlanarDev/test/` project environment
- The `@environment!` macro must be called within the `@eval` block
- All package imports should use the PlanarDev module structure

## Test Content Guidelines

### Test Naming and Organization
- Use descriptive test names that clearly indicate what is being tested
- Group related tests within the same function
- Use `@testset` blocks to organize test groups
- define mocks and structs at top level (global) or use @eval within a function
- if you want to mock functions, use overlay, like it's done in test_live
- do not implement test only types (structs, enums) in the test file

### Test Data and Setup
- Use realistic test data that represents actual usage scenarios
- Clean up any temporary files or data created during tests
- Use `@test` for simple assertions and `@test_throws` for exception testing
- if a test modifies persistent storage, ensure that whatever path, key, temp file is cleaned up after the test (or before depending on the test)

### Performance Considerations
- Tests should be reasonably fast (avoid long-running operations unless necessary)
- Use minimal data sets for testing
- Consider using `@test_broken` for known issues that need to be addressed

### Error Handling
- Test both success and failure scenarios
- Verify that appropriate errors are thrown for invalid inputs
- Test edge cases and boundary conditions

## Troubleshooting

### Precompilation Issues
- If tests fail with precompilation errors, try clearing the cache:
  ```bash
  julia --project=PlanarDev/test/ -e 'using Pkg; Pkg.precompile()'
  ```
- Use `--compile=min` flag for debugging: `julia --compile=min --project=PlanarDev/test/ ...`

### Missing Dependencies
- Ensure all required packages are available in the PlanarDev environment
- Check that local packages are properly developed: `Pkg.develop(path="PackageName")`

### Environment Issues
- Always use the correct project directory (`PlanarDev/test/`)
- Ensure the `@environment!` macro is called in test functions
- Verify imports follow the PlanarDev module structure

## Best Practices

### Code Quality
- Write tests that are easy to understand and maintain
- Use descriptive variable names and comments where necessary
- Follow the existing code style and conventions

### Test Coverage
- Aim for comprehensive test coverage of new functionality
- Test both happy path and error scenarios
- Include integration tests for complex workflows

### Documentation
- Document any complex test setup or assumptions
- Use clear test descriptions that explain the expected behavior
- Comment on any workarounds or known limitations

## Integration with CI/CD

### Continuous Integration
- Tests should pass in the CI environment
- Avoid tests that depend on external services or specific system configurations
- Use deterministic test data and random seeds where appropriate

### Test Reporting
- Use appropriate test assertions that provide clear failure messages
- Group related tests using `@testset` for better organization
- Ensure test output is clean and informative