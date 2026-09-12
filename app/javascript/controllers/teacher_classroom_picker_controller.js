import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["school", "grade", "options", "classroom"]
  static values = { url: String, selectedId: Number }

  changeSchool() {
    this.selectedIdValue = 0
    this.gradeTarget.value = ""
    this.loadOptions()
  }

  changeGrade() {
    this.selectedIdValue = 0
    this.loadOptions()
  }

  async loadOptions() {
    const url = new URL(this.urlValue, window.location.origin)
    this.updateSearchParam(url, "school_id", this.schoolTarget.value)
    this.updateSearchParam(url, "membership_grade", this.gradeTarget.value)
    this.updateSearchParam(url, "classroom_id", this.selectedIdValue > 0 ? this.selectedIdValue : "")

    const response = await fetch(url.toString(), {
      headers: { Accept: "text/html" }
    })
    if (!response.ok) return

    this.optionsTarget.innerHTML = await response.text()
  }

  updateSearchParam(url, key, value) {
    if (value === "") {
      url.searchParams.delete(key)
    } else {
      url.searchParams.set(key, value)
    }
  }
}
