import { requireProfile, type AppRole } from "@/lib/session";

const HOME: Record<AppRole, string> = {
  admin: "Admin: manage prices, customers, users and review changes.",
  manager: "Manager: create customers, confirm deliveries and assign drivers.",
  driver: "Driver: record deliveries.",
  customer: "Customer: view prices, place orders, pay and see reports.",
};

export default async function DashboardPage() {
  const profile = await requireProfile();
  return (
    <section className="space-y-2">
      <h1 className="text-xl font-semibold">Welcome, {profile.full_name}</h1>
      <p className="text-neutral-600">{HOME[profile.role]}</p>
    </section>
  );
}
