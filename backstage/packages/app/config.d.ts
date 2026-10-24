export interface Config {
  phoenix?: {
    /**
     * Shows the Microsoft Entra ID button on the sign-in page.
     * Set by app-config.entra.yaml (ENTRA_ENABLED=true).
     * @visibility frontend
     */
    entraEnabled?: boolean;
  };
}
