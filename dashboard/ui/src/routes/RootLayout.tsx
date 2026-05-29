import { NavLink, Outlet } from "react-router-dom"
import { Surface } from "@cloudflare/kumo"

const NAV = [
  { to: "/", label: "Inbox", end: true },
  { to: "/flows", label: "Flows", end: false }
]

export default function RootLayout() {
  return (
    <div className="grid h-full grid-cols-[16rem_1fr]">
      <Surface as="aside" className="flex flex-col gap-4 rounded-none border-r p-4">
        <div className="text-lg font-semibold">ColouredFlow Dashboard</div>
        <nav className="flex flex-col gap-1">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                [
                  "rounded px-3 py-2 text-sm",
                  isActive ? "bg-kumo-subtle font-medium" : "hover:bg-kumo-subtle/50"
                ].join(" ")
              }
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
      </Surface>
      <main className="overflow-auto p-6">
        <Outlet />
      </main>
    </div>
  )
}
