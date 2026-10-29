export default function AppLayout({ children }: LayoutProps<"/">) {
  return <div className="min-h-dvh bg-fb-grey">{children}</div>;
}
