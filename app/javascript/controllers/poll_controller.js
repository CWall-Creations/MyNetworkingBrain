import { Controller } from "@hotwired/stimulus"

// While a refresh is running, check every few seconds and reload when it's done.
export default class extends Controller {
  static values = { url: String }
  connect() {
    this.timer = setInterval(async () => {
      const html = await (await fetch(this.urlValue)).text()
      if (!html.includes("Refreshing")) { clearInterval(this.timer); Turbo.visit(location.href) }
    }, 4000)
  }
  disconnect() { clearInterval(this.timer) }
}
