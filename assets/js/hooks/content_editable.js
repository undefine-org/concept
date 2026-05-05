const ContentEditable = {
  mounted() {
    this._onBlur = () => {
      this.pushEventTo(this.el, "save_title", { value: this.el.innerText });
    };
    this._onKeydown = (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        this.el.blur();
      }
    };
    this.el.addEventListener("blur", this._onBlur);
    this.el.addEventListener("keydown", this._onKeydown);
  },

  destroyed() {
    this.el.removeEventListener("blur", this._onBlur);
    this.el.removeEventListener("keydown", this._onKeydown);
  },
};

export default ContentEditable;
