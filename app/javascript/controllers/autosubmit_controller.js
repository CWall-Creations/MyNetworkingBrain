import { Controller } from "@hotwired/stimulus"

// Submits the surrounding form when a field changes (closeness ratings).
export default class extends Controller {
  submit() { this.element.requestSubmit() }
}
