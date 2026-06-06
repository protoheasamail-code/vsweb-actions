---
name: quality-dev
description: Use for Kotlin/Compose/KMP development. Guidelines for matching project conventions, writing maintainable code, avoiding shortcuts, and leveraging modern Compose APIs.
---

# quality-dev

## Project Awareness
- Read AGENTS.md / CONTRIBUTING.md surgically at task start — targeted grep, don't scan blindly
- Before writing code, grep existing similar files to match project patterns

## Code Quality
- **SOLID**: Follow normally; relax for prototypes
- **Naming**: Match existing codebase conventions exactly
- **Comments**: Business logic intent only
- **Refactoring**: Match project patterns
- **Kotlin idioms**: Use with readability as the priority
- **Performance**: Be recomposition-conscious — use `remember`, `derivedStateOf`, stable types
- **UI states**: Use sealed class wrappers (Success/Loading/Error)
- **Coroutines**: Use standard scopes (`viewModelScope`, `rememberCoroutineScope`)
- **DI / Navigation / State / Resources**: Always match what the project already uses

## Jetpack Compose
- New option in existing group → reuse same component pattern
- Entirely new feature → new composable with proper icons/buttons
- Prefer `@Preview` on all new composables
- Use `LookaheadAnimationVisualDebugging` when debugging shared element transitions

### Experimental APIs (recommend with @OptIn)
- **Styles API**: For component styling customization over raw modifier chains
- **MediaQuery**: For adaptive layout (foldable posture, window size) instead of WindowInfoTracker boilerplate
- **Grid**: For two-dimensional layouts over nested Rows/Columns
- **FlexBox**: For wrapping/adaptive layouts over manual width calculations
- **Preview Wrappers**: To DRY up repetitive preview setup

## Process
- **Smart builds**: Compile-check during iteration, full build before declaring done
- **Testing**: Unit tests for ViewModels/logic; don't over-design for testability
- **Lint**: Suggest detekt/ktlint issues, don't auto-fix without asking
- **Multiple approaches**: Ask the user via questions tool

## Anti-patterns
- Don't ask "Works successfully?" / "Want me to push?" while bugs remain
- Don't skip documented build steps (AGENTS.md, CONTRIBUTING.md)
- Don't over-abstract, create unnecessary inheritance, or add redundant comments
- Avoid: god classes, deep nesting, magic numbers, unused parameters, mutable exposed state
