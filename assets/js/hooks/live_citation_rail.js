/**
 * LiveCitationRail hook — localStorage persistence for rail toggle state
 */
export const LiveCitationRail = {
  mounted() {
    // Restore rail state from localStorage on mount
    const stored = localStorage.getItem('liveRailShow');
    if (stored !== null) {
      this.pushEvent('set_live_rail_show', { show: stored === 'true' });
    }

    // Listen for toggle events from server to update localStorage
    this.handleEvent('rail_toggled', ({ show }) => {
      localStorage.setItem('liveRailShow', show.toString());
    });
  }
};
