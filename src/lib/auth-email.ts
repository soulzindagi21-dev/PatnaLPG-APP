// Customers and staff log in with a 10-digit mobile number. Supabase Auth needs an
// email, so each mobile maps to a hidden address on an internal domain.
const DOMAIN = process.env.AUTH_SYNTHETIC_EMAIL_DOMAIN ?? "login.patnalpg.com";

export const MOBILE_RE = /^[0-9]{10}$/;

export function normalizeMobile(input: string): string {
  const digits = input.replace(/\D/g, "");
  return digits.length > 10 ? digits.slice(-10) : digits;
}

export function mobileToEmail(mobile: string): string {
  return `${mobile}@${DOMAIN}`;
}
