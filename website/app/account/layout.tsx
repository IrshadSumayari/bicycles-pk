import { AccountNavigation } from "@/components/account-navigation";
export const metadata = { robots: { index: false, follow: false } };
export default function AccountLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <section className="section account-shell">
      <AccountNavigation />
      <div className="account-content">{children}</div>
    </section>
  );
}
