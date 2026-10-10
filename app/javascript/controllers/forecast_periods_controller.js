import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "detail"]

  connect() {
    const selected = this.cardTargets.findIndex(card => card.getAttribute("aria-pressed") === "true")
    this.show(selected < 0 ? 0 : selected)
  }

  select(event) {
    this.show(event.params.index)
  }

  show(index) {
    if (!this.detailTargets[index]) return

    this.cardTargets.forEach((card, position) => {
      card.setAttribute("aria-pressed", String(position === index))
    })
    this.detailTargets.forEach((detail, position) => {
      detail.hidden = position !== index
    })
  }
}
