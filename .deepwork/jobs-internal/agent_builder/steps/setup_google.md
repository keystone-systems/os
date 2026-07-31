# Set Up Google

## Objective

Sign into Google/Gmail via the browser using credentials from rbw. This establishes the Google session needed for OAuth flows to other services.

## Task

Use the Chrome DevTools MCP tools to navigate to Gmail and complete the Google sign-in flow.

### Process

1. **Retrieve credentials**
   - Get the Google account email from SOUL.md (the Gmail entry)
   - Get the password from rbw: `rbw get www.google.com`

2. **Navigate to Gmail**
   - Use `navigate_page` to go to `https://accounts.google.com/AccountChooser/signinchooser?service=mail&continue=https%3A%2F%2Fmail.google.com%2Fmail%2F&flowName=GlifWebSignIn&flowEntry=AccountChooser`
   - Take a snapshot to see the current page state

3. **Complete sign-in**
   - Enter the email address in the email field
   - Click "Next"
   - If prompted for passkey, click "Try another way" then "Enter your password"
   - Enter the password from rbw
   - Click "Next"
   - Handle any additional prompts (2FA, consent screens)

4. **Verify sign-in**
   - Confirm you've reached the Gmail inbox (URL should contain `mail.google.com/mail`)
   - Take a snapshot to confirm the inbox is visible

### Troubleshooting

- **Passkey prompt**: Always click "Try another way" → "Enter your password" since passkeys aren't available in this environment
- **2FA prompt**: If a 2FA code is required, check rbw for a TOTP entry: `rbw code www.google.com`
- **Account recovery prompt**: Skip if possible, or follow the prompts

## Output Format

### google_status.md

```markdown
# Google Sign-In Status

**Status**: Success / Failed
**Account**: [email address]
**Date**: [current date]

## Details

- Signed into Gmail inbox: Yes/No
- Session established for OAuth: Yes/No

## Issues

[Any issues encountered during sign-in, or "None"]
```

## Quality Criteria

- Successfully signed into Gmail (inbox page visible)
- Google session is active and usable for OAuth flows
- No credentials appear in the output file

## Context

Google sign-in is the foundation for OAuth-based logins to other services (GitHub, GitLab, etc.). This step must succeed before the parallel GitHub and Forgejo setup steps can proceed.
