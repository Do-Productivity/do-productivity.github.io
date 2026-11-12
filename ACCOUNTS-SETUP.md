# Letting friends sync across their devices

Right now each person's list lives only in the browser they opened it in.
That is already private — there is no shared server for anyone to read. What
it does not do is follow them from phone to laptop.

This adds that. **5 minutes, $0, and no Google setup.** People sign in by
clicking a one-time link emailed to them: no password to invent, nothing to
install.

The code is already written and sitting dormant in `index.html`. It switches
itself on the moment the two values from step 4 are filled in.

---

## 1. Create the project

1. <https://supabase.com> → **Start your project** → sign in with GitHub.
2. **New project**, name it `my-todo-list`, region **Frankfurt (eu-central-1)**
   — the closest to Egypt.
3. It generates a database password. Save it in your password manager; this
   app never uses it.
4. Wait ~2 minutes while it builds.

## 2. Create the table

**SQL Editor** → **New query** → paste → **Run**:

```sql
-- One row per person. The whole sync document goes in `doc`, which leaves the
-- app's existing merge logic untouched — only the transport changes.
create table public.documents (
  user_id    uuid primary key references auth.users on delete cascade,
  doc        jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- This is the part that makes it private. Without it any signed-in person
-- could read every row; with it the database itself refuses. The browser is
-- never trusted to do the filtering.
alter table public.documents enable row level security;

create policy "read own document"   on public.documents
  for select using (auth.uid() = user_id);

create policy "insert own document" on public.documents
  for insert with check (auth.uid() = user_id);

create policy "update own document" on public.documents
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

Expect: `Success. No rows returned.`

## 3. Let the app receive people back after they click the link

**Authentication** → **URL Configuration**:

- **Site URL:** `https://do-productivity.github.io/`
- **Redirect URLs** — add both:
  - `https://do-productivity.github.io/`
  - `http://localhost:8642/`

Skip this and sign-in completes but then refuses to return to the app.

## 4. Send me two values

**Project Settings** → **API**:

- **Project URL** — like `https://abcdefghijkl.supabase.co`
- **anon public** key — a long string starting `eyJ…`

Paste both into the chat and I'll wire them in and test sign-in.

> Send the **anon public** key. It is designed to be public and ships inside
> the page on every site that uses Supabase; the policies in step 2 are what
> protect the data. Never send the **service_role** key — that one bypasses
> those policies completely.

---

## What your friends will see

Sync panel → their email → a link arrives → they tap it → done. Their list
then follows them to any browser they sign into, and nobody else can read it,
including you.

## What happens to your own data

Nothing is taken away. Your tasks are in a GitHub Gist today and both the
home screen widget and the Apple Calendar feed read it. After you sign in:

- the account becomes the source of truth for syncing between your devices,
- the gist carries on being written after every upload (`gistMirror`), so the
  widget and the `webcal://` subscription keep working exactly as now,
- the first sign-in on a device that has no cloud data yet uploads what is
  already there, so nothing is lost.

## Later, if you want the Gmail button

It needs a Google Cloud OAuth client (~10 min) and then flipping
`CLOUD_GOOGLE` to `true` in `index.html`. The button is already built and
hidden — nothing else changes. Not needed for any of the above.
