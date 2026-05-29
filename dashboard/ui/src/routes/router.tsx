import { createBrowserRouter, type RouteObject } from "react-router-dom"

import RootLayout from "./RootLayout"
import InboxPage from "./InboxPage"
import EnactmentDetailPage from "./EnactmentDetailPage"
import FlowCatalogPage from "./FlowCatalogPage"
import NotFoundPage from "./NotFoundPage"

export const routes: RouteObject[] = [
  {
    path: "/",
    element: <RootLayout />,
    children: [
      { index: true, element: <InboxPage /> },
      { path: "enactments/:id", element: <EnactmentDetailPage /> },
      { path: "flows", element: <FlowCatalogPage /> },
      { path: "flows/:module", element: <FlowCatalogPage /> },
      { path: "*", element: <NotFoundPage /> }
    ]
  }
]

export const router = createBrowserRouter(routes)
