import { Controller } from "@hotwired/stimulus"
import flatpickr from "flatpickr"

export default class extends Controller {
    static targets = ["button", "input", "effectiveFrom", "effectiveTo"]

    select(event) {
        event.preventDefault()
        const link = event.target.closest("[data-value]")
        if (!link) return

        const value = link.dataset.value
        const label = link.textContent.trim()

        this.buttonTarget.textContent = label
        this.inputTarget.value = value
    }

    connect() {
        // Initialize button label from saved value
        if (this.inputTarget.value) {
            const item = this.element.querySelector(`[data-value="${this.inputTarget.value}"]`)
            if (item) this.buttonTarget.textContent = item.textContent.trim()
        }

        // Init Flatpickr on date fields
        flatpickr(this.effectiveFromTarget, {
            enableTime: true,
            dateFormat: "Y-m-d H:i",
            altInput: true,
            altFormat: "F j, Y h:i K"
        })

        flatpickr(this.effectiveToTarget, {
            enableTime: true,
            dateFormat: "Y-m-d H:i",
            altInput: true,
            altFormat: "F j, Y h:i K"
        })
    }
}

