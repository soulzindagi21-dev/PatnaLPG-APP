# Patna LPG App

Next.js (App Router) on Vercel, Supabase backend (Postgres, Auth, private Storage, RLS).
Requirements and build plan: `../app-spec.md`.

## Setup

1. Create a Supabase project (Mumbai region) and a Vercel project linked to this repo.
2. Copy `.env.example` to `.env.local` and fill in the Supabase values.
3. Apply the database schema: paste `supabase/migrations/20261112000001_phase1_foundation.sql`
   into the Supabase SQL editor and run it.
4. Create the first admin:

   ```bash
   node --env-file=.env.local scripts/create-user.mjs 9XXXXXXXXX "Admin Name" admin "a-strong-password"
   ```

5. Run locally:

   ```bash
   npm install
   npm run dev
   ```

Login is by 10-digit mobile number. Each mobile maps to a hidden email
(`<mobile>@login.patnalpg.com`) in Supabase Auth.

Next.js 16 note: the request interceptor is `src/proxy.ts` (formerly middleware).
