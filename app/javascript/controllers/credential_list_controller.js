import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row"]
  static values = { returnUrl: String, header: String, copied: String }

  connect() {
    if (this.hasReturnUrlValue) window.history.replaceState(window.history.state, "", this.returnUrlValue)
  }

  copyAll(event) {
    this.copy([this.headerValue, ...this.rowTargets.map((row) => row.dataset.copyText)].join("\n"), event.currentTarget)
  }

  copyRow(event) {
    const row = event.currentTarget.closest("[data-credential-list-target='row']")
    this.copy(row.dataset.copyText, event.currentTarget)
  }

  print() {
    window.print()
  }

  async copy(text, button) {
    await navigator.clipboard.writeText(text)
    const original = button.textContent
    button.textContent = this.copiedValue
    window.setTimeout(() => { button.textContent = original }, 1200)
  }
}
