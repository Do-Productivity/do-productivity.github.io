# Turning on accounts (so friends can use the app)

The code is already in `index.html`. It stays dormant until the two constants
near the top of the sync section are filled in, so nothing breaks while this
is half-done.

Everything below is on free tiers. Total cost: **$0**.

---

## 1. Create the project (3 minutes)

1. Go to <https://supabase.com> and sign in with GitHub.
2. **New project**. Name it `my-todo-list`. Pick the region closest to you
   (`eu-central-1` / Frankfurt is the nearest to Egypt).
3. It asks for a database password — let it generate one and save it in your
   password manager. You will not need it for this app.
4. Wait ~2 minutes for it to finish building.

## 2. Create the table (1 minute)

Open **SQL Editor** → **New query**, paste this, press **Run**:

```sql
-- One row per person. The whole sync document lives in `doc`, which keeps the
-- app's existing merge logic untouched — only the transport changed.
create table public.documents (
  user_id    uuid primary key references auth.users on delete cascade,
  doc        jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Row Level Security is what makes this private. Without it, any signed-in
-- person could read every row. With it, the database itself refuses — the
-- browser is never trusted to do the filtering.
alter table public.documents enable row level security;

create policy "read own document"   on public.documents
  for select using (auth.uid() = user_id);

create policy "insert own document" on public.documents
  for insert with check (auth.uid() = user_id);

create policy "update own document" on public.documents
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

You should see `Success. No rows returned.`

## 3. Allow the app to send people back after sign-in (1 minute)

**Authentication** → **URL Configuration**:

- **Site URL:** `https://ahmedmohsen18.github.io/my-todo-list/`
- **Redirect URLs** — add both:
  - `https://ahmedmohsen18.github.io/my-todo-list/`
  - `http://localhost:8642/`

Without this, sign-in completes and then refuses to return to the app.

## 4. Give me the two values

**Project Settings** → **API**:

- **Project URL** — looks like `https://abcdefghijkl.supabase.co`
- **anon public** key — a long string starting `eyJ…`

Paste both to me and I'll wire them in.

> The anon key is *designed* to be public — it ships inside the page on every
> site that uses Supabase. It grants nothing on its own; the RLS policies above
> are what protect the data. Do **not** paste the `service_role` key, which is
> the opposite: it bypasses RLS entirely.

---

## 5. Sign in with Google (optional, ~10 minutes — you do this part)

Email sign-in links work the moment steps 1–4 are done, with no extra setup.
Google is nicer for friends but needs a Google Cloud project:

1. <https://console.cloud.google.com> → new project.
2. **APIs & Services** → **OAuth consent screen** → External → fill in app name
   and your email → add yourself as a test user (or publish the app).
3. **Credentials** → **Create credentials** → **OAuth client ID** → Web
   application.
4. **Authorised redirect URI** — paste the callback shown in Supabase under
   **Authentication → Providers → Google**. It looks like
   `https://<project>.supabase.co/auth/v1/callback`.
5. Copy the **Client ID** and **Client secret** into that same Supabase Google
   provider page, and enable it.

Nothing in the app changes — the button is already there and starts working
once the provider is enabled.

---

## What happens to your existing data

Your tasks are in a GitHub Gist today, and the widget and the Apple Calendar
feed both read it. Signing in does **not** take that away:

- The account becomes the source of truth for syncing between devices.
- The gist keeps being written after every successful upload (`gistMirror`),
  so the Scriptable widget and the `webcal://` calendar subscription carry on
  working exactly as they do now.
- The first sign-in on a device with no cloud data yet uploads what is already
  on that device, so nothing is lost.
