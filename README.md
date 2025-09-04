# Tiny Chat (Supabase + GitHub Pages)

A free, static website that hosts a real-time chat room using Supabase as the backend. Deployable on GitHub Pages.

## Quick Start

1. **Create a Supabase project (Free plan is fine)**  
   - Go to https://supabase.com → New project.  
   - In **Settings → API**, copy **Project URL** and **anon key**.

2. **Create the database objects**  
   - Open **SQL Editor** and paste/run the contents of `schema.sql`.  
   - This creates a `messages` table, indexes, basic RLS policies, and enables realtime.

3. **Configure the website**  
   - Edit `config.js` and set:
     ```js
     window.__TCFG = {
       SUPABASE_URL: "https://YOUR-PROJECT-REF.supabase.co",
       SUPABASE_ANON: "YOUR-ANON-KEY"
     };
     ```

4. **Deploy to GitHub Pages**  
   - New GitHub repo (e.g., `tiny-chat`).  
   - Add/commit `index.html`, `config.js`, `schema.sql`, `README.md`.  
   - Repo → **Settings → Pages** → Source: "Deploy from a branch" → Branch: `main` → Folder: `/ (root)`.  
   - Visit: `https://<username>.github.io/tiny-chat/?room=general`

## How it works

- **Storage**: Messages are stored in Postgres (`public.messages`).  
- **Realtime**: Supabase Realtime pushes new rows to connected clients.  
- **Rooms**: Each URL query `?room=...` selects an isolated room.  
- **Presence**: Realtime Presence tracks who’s currently on the page (anonymous, using the name field).  
- **Typing indicator**: Uses Realtime broadcast events.  
- **Pagination**: "Load older" fetches older rows via `lt('created_at', earliest)`.

## Optional Upgrades

### A) Soft retention (prune old messages)

Run periodically (e.g., monthly) in the SQL editor:

```sql
delete from public.messages
where created_at < now() - interval '90 days';
```

### B) Attachment uploads

1. In Supabase **Storage**, create a public bucket `chat-uploads` (or keep it private and serve via signed URLs).  
2. In `index.html`, add a file input and upload using the JS SDK:
   ```js
   const file = input.files[0];
   const path = `${ROOM}/${crypto.randomUUID()}-${file.name}`;
   const { data, error } = await supabase.storage.from('chat-uploads').upload(path, file);
   const { data: pub } = supabase.storage.from('chat-uploads').getPublicUrl(path);
   // Insert a message with the file link in "body"
   ```

### C) Lock down posting with Auth

1. **Add a column** to `messages`:
   ```sql
   alter table public.messages add column user_id uuid;
   ```
2. **Update policies**:
   ```sql
   drop policy if exists "post messages (1/s throttle)" on public.messages;
   create policy "post messages (auth posts, 1/s)" on public.messages
     for insert with check (
       auth.uid() is not null
       and messages.user_id = auth.uid()
       and not exists (
         select 1 from public.messages m
         where m.room = messages.room
           and m.user_name = messages.user_name
           and m.created_at > now() - interval '1 second'
       )
     );

   create policy "delete own messages" on public.messages
     for delete using (auth.uid() = user_id);
   ```
3. **Client**: sign in users (email OTP, OAuth, etc.) and include `user_id` when inserting:
   ```js
   const { data: { user } } = await supabase.auth.getUser();
   await supabase.from('messages').insert({ room, user_name, body, user_id: user.id });
   ```

### D) Basic moderation

Add a `bans(room, user_name)` table and extend the insert policy:

```sql
create table if not exists public.bans (
  room text not null,
  user_name text not null,
  primary key (room, user_name)
);

-- In the insert policy's WITH CHECK, add:
and not exists (
  select 1 from public.bans b
   where b.room = messages.room
     and b.user_name = messages.user_name
)
```

### E) Theming

Edit the CSS variables in `<style>` at the top of `index.html`.

## Notes & Tips

- Only the **anon** key belongs in the browser. Never use your service role key on a static site.  
- If realtime seems inactive, re-run:  
  ```sql
  alter publication supabase_realtime add table public.messages;
  ```
- GitHub Pages is static and supports client-side apps without extra config.