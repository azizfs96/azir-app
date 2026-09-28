# Wasla UX/UI Review Skill

## Purpose

This skill is used to perform a comprehensive UX/UI, navigation,
state-management, lifecycle, async-data, and user-flow review of the
Wasla application.

The review MUST NOT be limited to visual design.

The reviewer must behave as:

1. Senior Product Designer
2. Senior Flutter Engineer
3. QA Engineer
4. Mobile UX specialist

The goal is to find issues that a normal visual UI review would miss.

A screen is NOT considered complete simply because it works on the
first visit.

---

# 1. Core Review Principle

Always test the application as a real user.

For every important flow, review:

1. First entry
2. Forward navigation
3. Back navigation
4. Re-entry
5. State restoration
6. State changes
7. Loading states
8. Error states
9. Retry behavior
10. Network failures
11. Async operations
12. Stale data
13. Empty states
14. App lifecycle where applicable

Do not assume that state is correct because the UI initially renders
correctly.

---

# 2. Booking Flow

The booking flow is a critical business flow and requires deeper
testing.

Typical flow:

Service
→ Date
→ Staff
→ Time
→ Confirmation

The exact flow may differ depending on merchant configuration.

Test all available configurations.

---

# 3. Back Navigation Testing

For every booking step test:

Normal:

Date
→ Time
→ Continue

Then:

Date
→ Time
→ Continue
→ Back
→ Time

Verify:

- No exception
- No blank screen
- No infinite loading
- Availability loads correctly
- Previously selected state is correct
- API requests behave correctly
- User can continue
- No stale availability is displayed

---

# 4. Multiple Back/Forward Cycles

Test:

Date
→ Time
→ Back
→ Time
→ Back
→ Time
→ Next
→ Back
→ Next

Repeat this multiple times.

The application must remain stable.

Look specifically for:

- duplicated API requests
- stale state
- missing state
- disposed widgets
- loading states stuck forever
- incorrect selected values
- incorrect availability

---

# 5. Change Date

Test:

Date A
→ Time
→ Back
→ Date B
→ Time

Verify:

- Date B availability is loaded
- Date A slots are not displayed
- Previous time selection is revalidated
- Invalid selected time is cleared
- Loading state is correct
- API request uses Date B

---

# 6. Change Service

Test:

Service A
→ Date
→ Time
→ Back
→ Service B
→ Time

Verify:

- Availability is recalculated
- Service A availability is not reused
- Duration is correct
- Selected time is revalidated
- API requests use Service B

---

# 7. Change Staff

If staff selection is enabled:

Staff A
→ Date
→ Time
→ Back
→ Staff B
→ Time

Verify:

- Availability is recalculated
- Staff A slots are not reused
- Staff B availability is displayed
- Previous time is revalidated

If staff selection is disabled:

Verify that the flow works without requiring staff selection.

---

# 8. Merchant Configuration

Wasla supports different merchant configurations.

Test at minimum:

### Configuration A

Staff selection enabled.

### Configuration B

Staff selection disabled.

### Configuration C

Customer chooses staff.

### Configuration D

System automatically assigns staff.

The UI must adapt without showing irrelevant controls.

---

# 9. Async Request Safety

Inspect asynchronous operations carefully.

Test scenarios such as:

Screen A
→ API request starts
→ Back
→ Screen A again
→ second API request starts

Verify that an older response cannot overwrite newer state.

Look for:

- race conditions
- stale responses
- duplicate requests
- requests after dispose
- state updates after widget disposal
- incorrect loading flags
- incorrect error states

---

# 10. Loading States

Every API-driven screen must have a clear loading state.

Check:

- initial loading
- refresh loading
- loading after navigation
- loading after changing parameters
- loading after retry

Never leave the user with:

- infinite spinner
- blank page
- disabled controls without explanation

---

# 11. Error Handling

Every network/API failure must have a recovery path.

Verify that errors:

- are understandable
- do not expose technical exceptions
- do not expose SQL/API internals
- provide Retry when appropriate
- allow the user to recover

Bad:

"Null check operator used on a null value"

Good:

"Unable to load available times. Please try again."

---

# 12. Empty States

Test:

- no available times
- no services
- no staff
- no bookings
- no branches
- no results

Every empty state must explain:

1. What happened
2. What the user can do next

---

# 13. Stale Data

Whenever any upstream booking parameter changes:

- Service
- Date
- Staff
- Branch

dependent data must be revalidated.

Never blindly reuse availability from a previous state.

Example:

Date = Monday
Time = 10:00

Change Date → Tuesday

The application must NOT continue displaying Monday's availability.

---

# 14. Navigation State

For every screen determine intentionally whether returning to it
should:

1. Restore state
2. Reload data
3. Recalculate data
4. Clear dependent state

Do not rely on accidental widget lifecycle behavior.

---

# 15. App Lifecycle

Where applicable test:

- background application
- return to foreground
- interrupted request
- network disconnected
- network restored

Verify that the application recovers correctly.

---

# 16. UX Consistency

Review:

- typography
- spacing
- alignment
- buttons
- cards
- forms
- icons
- colors
- loading indicators
- error messages
- empty states
- navigation
- bottom sheets
- dialogs

Ensure the UI behaves consistently across the application.

---

# 17. Mobile Usability

Review:

- touch target sizes
- keyboard behavior
- scrolling
- content overflow
- safe areas
- small screens
- large screens
- portrait orientation
- text overflow
- long Arabic/English text

The interface must remain usable on real mobile devices.

---

# 18. Accessibility

Check:

- readable text
- sufficient contrast
- touch target size
- semantic labels where appropriate
- screen-reader compatibility where applicable
- meaningful error messages

---

# 19. Performance UX

Look for:

- unnecessary rebuilds
- excessive API requests
- unnecessary database/cache calls
- large widget rebuilds
- slow screen transitions
- unnecessary animations
- large images
- unnecessary network requests

Do not optimize prematurely.

Identify measurable problems first.

---

# 20. Regression Test Requirement

Every discovered bug must result in a regression test when technically
appropriate.

Example:

Bug:

Date
→ Time
→ Next
→ Back
→ Time

Availability fails to load.

Required regression test:

1. Open booking flow.
2. Select service.
3. Select date.
4. Load time slots.
5. Navigate forward.
6. Navigate back.
7. Re-enter time screen.
8. Verify availability loads.
9. Verify no exception.
10. Verify correct date/service context.

A bug is NOT considered fixed until:

1. It is reproduced.
2. Root cause is identified.
3. Code is fixed.
4. Regression test is added.
5. Regression test passes.

---

# 21. Bug Severity

Use:

### Critical

Blocks booking or causes data corruption,
security issue, crash, or major business failure.

### High

Major functionality broken but workaround exists.

### Medium

Noticeable functional or UX problem.

### Low

Minor visual or usability issue.

---

# 22. Bug Report Format

For every issue use:

## BUG-[number]

**Severity:**

Critical / High / Medium / Low

**Feature:**

**Screen:**

**Steps to reproduce:**

1.
2.
3.

**Expected:**

**Actual:**

**Root cause:**

Only state the root cause after inspecting the implementation.

**Recommended fix:**

**Regression test:**

---

# 23. Review Process

When asked to review a feature:

### Step 1

Inspect the actual implementation.

### Step 2

Understand the state model.

### Step 3

Understand navigation.

### Step 4

Understand API/data dependencies.

### Step 5

Test the normal user journey.

### Step 6

Test Back/Forward navigation.

### Step 7

Test state changes.

### Step 8

Test async/error/loading scenarios.

### Step 9

Inspect automated tests.

### Step 10

Report all findings.

Do NOT modify code during the audit unless explicitly requested.

---

# 24. Fix Process

When explicitly asked to fix the issues:

For each issue:

1. Confirm the bug.
2. Identify root cause.
3. Implement the smallest correct fix.
4. Add regression coverage.
5. Run relevant tests.
6. Run the full test suite when appropriate.
7. Verify no unrelated behavior changed.

Do NOT:

- remove existing tests
- weaken assertions
- hide errors
- disable validation
- rewrite unrelated architecture
- make speculative optimizations

---

# 25. Definition of Done

A feature is NOT considered complete when only the happy path works.

A feature is complete only when:

- Happy path works
- Back navigation works
- Forward navigation works
- Re-entry works
- State is consistent
- Dependent state is invalidated correctly
- Async operations are safe
- Loading states work
- Errors are recoverable
- Retry works
- Empty states work
- Stale data is handled
- Relevant edge cases are tested
- Regression tests exist
- Existing tests pass

---

# 26. Final Audit Report

At the end provide:

## Critical Issues

## High Issues

## Medium Issues

## Low Issues

## Missing Tests

## UX Improvements

## Performance Findings

## Final Recommendation

Use one of:

- NOT READY
- NEEDS FIXES
- READY FOR QA
- PRODUCTION READY

Never mark the application Production Ready if Critical or High
functional issues remain.
