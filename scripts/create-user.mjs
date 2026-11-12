// Creates a user (auth account + profile). Use it once to create the first admin.
//
//   node --env-file=.env.local scripts/create-user.mjs <mobile> "<Full Name>" <role> [password]
//
// role: admin | manager | driver | customer. Password defaults to DEFAULT_CUSTOMER_PASSWORD.
import { createClient } from "@supabase/supabase-js";

const [mobile, fullName, role, passwordArg] = process.argv.slice(2);
const ROLES = ["admin", "manager", "driver", "customer"];

if (!/^[0-9]{10}$/.test(mobile ?? "") || !fullName || !ROLES.includes(role)) {
  console.error('Usage: node --env-file=.env.local scripts/create-user.mjs <10-digit mobile> "<Full Name>" <admin|manager|driver|customer> [password]');
  process.exit(1);
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.local");
  process.exit(1);
}

const domain = process.env.AUTH_SYNTHETIC_EMAIL_DOMAIN ?? "login.patnalpg.com";
const password = passwordArg ?? process.env.DEFAULT_CUSTOMER_PASSWORD ?? "123456";
const supabase = createClient(url, key, { auth: { persistSession: false } });

const { data, error } = await supabase.auth.admin.createUser({
  email: `${mobile}@${domain}`,
  password,
  email_confirm: true,
});
if (error) {
  console.error("Could not create auth user:", error.message);
  process.exit(1);
}

const { error: profileError } = await supabase
  .from("profiles")
  .insert({ id: data.user.id, role, full_name: fullName, mobile });
if (profileError) {
  await supabase.auth.admin.deleteUser(data.user.id);
  console.error("Could not create profile (auth user rolled back):", profileError.message);
  process.exit(1);
}

console.log(`Created ${role} ${fullName} (${mobile}).`);
