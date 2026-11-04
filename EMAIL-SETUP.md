# Making the sign-in emails actually arrive

## What is wrong

Supabase ships with a built-in mail sender that allows **about two messages
per hour** across the whole project. It exists so you can test, and their own
docs say not to rely on it. Proof it is already the binding constraint — a
second send to the project returns:

```json
{"code":429,"error_code":"over_email_send_rate_limit","msg":"email rate limit exceeded"}
```

Those messages also come from a shared address with no reputation behind it,
so the ones that do get sent very often land in spam.

With friends this fails in the worst way: the third person to sign in simply
never receives anything, and nothing on screen says why.

**First, go and look in your spam folder** — your original link may be sitting
there. The rate limit resets about an hour after the last send.

The real fix is to give Supabase your own mail sender. Both options below are
free and neither needs you to own a domain.

---

## Option A — Gmail (fastest, ~5 minutes)

You already have the account, and the link arrives from an address your
friends recognise, which helps it stay out of spam.

1. **2-Step Verification must be on**: <https://myaccount.google.com/security>
   → turn it on if it is not already. App passwords do not exist without it.
2. Go to <https://myaccount.google.com/apppasswords>, name it `Supabase`, and
   create it. Google shows a 16-character password **once** — copy it.
3. In Supabase: **Authentication** → **Emails** → **SMTP Settings** → enable
   **Custom SMTP** and fill in:

   | Field | Value |
   |---|---|
   | Host | `smtp.gmail.com` |
   | Port | `465` |
   | Username | your full Gmail address |
   | Password | the 16-character app password |
   | Sender email | the same Gmail address |
   | Sender name | `My To Do List` |

4. Save.

Limit: 500 messages a day. For friends that is effectively unlimited.

> The app password is a real credential — it goes straight from Google into
> the Supabase form. Do not paste it into this chat; I do not need it and
> should not have it.

## Option B — Brevo (~10 minutes, better long term)

Worth it if this ever goes past friends: it is built for this kind of mail,
gives you delivery logs, and keeps your personal Gmail out of it.

1. <https://www.brevo.com> → sign up free (300 emails/day).
2. Verify your sender address when prompted — a single email address is
   enough, you do not need a domain.
3. **SMTP & API** → **SMTP** tab → copy the login and the SMTP key.
4. Put those into the same Supabase **SMTP Settings** form:

   | Field | Value |
   |---|---|
   | Host | `smtp-relay.brevo.com` |
   | Port | `587` |
   | Username | the Brevo SMTP login |
   | Password | the Brevo SMTP key |
   | Sender email | the address you verified |

---

## After either one

Raise the ceiling the built-in sender imposed: **Authentication** →
**Rate Limits** → set **Emails per hour** to something like `100`. It stays
at the old low number otherwise, and you will keep hitting 429 with a working
mail service behind it.

Then test: Sync → your email → the link should arrive in under a minute.
