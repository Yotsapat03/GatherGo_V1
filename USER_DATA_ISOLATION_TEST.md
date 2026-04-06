# User Data Isolation Manual Test

## Preconditions
- Backend and Flutter app are running against the same database.
- No user is currently logged in.

## Test Users
- User A: `usera_<timestamp>@example.com`
- User B: `userb_<timestamp>@example.com`

## Steps
1. Sign up User A.
2. Log in as User A.
3. Join at least one Big Event as User A (complete booking/payment slip flow).
4. Open Joined Event / history screens and confirm User A records are visible.
5. Log out (or close app), then log in as User B.
6. Open Joined Event / history screens.
7. Confirm User B does not see User A records.
8. Join one event as User B.
9. Confirm User B only sees User B records.
10. Log back in as User A and confirm User A still only sees User A records.

## Expected Result
- No screen should show rows from another user.
- Requests missing or conflicting `user_id` should return HTTP 400.
- Payment slip upload for a booking that does not belong to the logged-in user should return HTTP 404.
