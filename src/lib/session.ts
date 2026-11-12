import "server-only";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type AppRole = "admin" | "manager" | "driver" | "customer";

export type SessionProfile = {
  id: string;
  role: AppRole;
  full_name: string;
  mobile: string;
};

/** Returns the signed-in, active profile, or redirects to /login. */
export async function requireProfile(allowed?: AppRole[]): Promise<SessionProfile> {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, role, full_name, mobile, active")
    .eq("id", auth.user.id)
    .single();

  if (!profile || !profile.active) {
    await supabase.auth.signOut();
    redirect("/login");
  }
  if (allowed && !allowed.includes(profile.role)) redirect("/dashboard");
  return profile;
}
