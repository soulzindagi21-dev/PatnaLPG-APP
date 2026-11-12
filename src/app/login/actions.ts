"use server";

import { redirect } from "next/navigation";
import { MOBILE_RE, mobileToEmail, normalizeMobile } from "@/lib/auth-email";
import { createClient } from "@/lib/supabase/server";

export type LoginState = { error?: string };

export async function login(_prev: LoginState, formData: FormData): Promise<LoginState> {
  const mobile = normalizeMobile(String(formData.get("mobile") ?? ""));
  const password = String(formData.get("password") ?? "");

  if (!MOBILE_RE.test(mobile)) return { error: "Enter a valid 10-digit mobile number." };
  if (!password) return { error: "Enter your password." };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({
    email: mobileToEmail(mobile),
    password,
  });
  if (error) return { error: "Mobile number or password is incorrect." };

  redirect("/dashboard");
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
