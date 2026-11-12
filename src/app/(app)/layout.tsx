import { logout } from "@/app/login/actions";
import { requireProfile } from "@/lib/session";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const profile = await requireProfile();
  return (
    <div className="min-h-screen bg-neutral-50">
      <header className="flex items-center justify-between border-b border-neutral-200 bg-white px-4 py-3">
        <span className="font-semibold text-neutral-900">Patna LPG</span>
        <div className="flex items-center gap-3 text-sm text-neutral-600">
          <span>
            {profile.full_name} ({profile.role})
          </span>
          <form action={logout}>
            <button className="rounded border border-neutral-300 px-2 py-1">Sign out</button>
          </form>
        </div>
      </header>
      <div className="mx-auto max-w-5xl p-4">{children}</div>
    </div>
  );
}
