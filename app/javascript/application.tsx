import '@vitejs/plugin-react/preamble'
import { createRoot } from "react-dom/client"
import App from "./components/App"

document.addEventListener("DOMContentLoaded", () => {
  const container = document.getElementById("react-root")
  if (container) {
    const root = createRoot(container)
    root.render(<App />)
  }
})
