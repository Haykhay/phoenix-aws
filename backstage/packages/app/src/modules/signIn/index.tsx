import { createFrontendModule } from '@backstage/frontend-plugin-api';
import {
  SignInPageBlueprint,
  SignInPageProps,
} from '@backstage/plugin-app-react';
import { SignInPage } from '@backstage/core-components';
import {
  configApiRef,
  microsoftAuthApiRef,
  useApi,
} from '@backstage/core-plugin-api';

// Guest always (local testing); Entra ID when phoenix.entraEnabled is set,
// which app-config.entra.yaml does when ENTRA_ENABLED=true.
function PhoenixSignInPage(props: SignInPageProps) {
  const entra =
    useApi(configApiRef).getOptionalBoolean('phoenix.entraEnabled') ?? false;
  return (
    <SignInPage
      {...props}
      providers={[
        'guest',
        ...(entra
          ? [
              {
                id: 'microsoft-auth-provider',
                title: 'Microsoft Entra ID',
                message: 'Sign in with your company account',
                apiRef: microsoftAuthApiRef,
              },
            ]
          : []),
      ]}
    />
  );
}

export const signInModule = createFrontendModule({
  pluginId: 'app',
  extensions: [
    SignInPageBlueprint.make({
      params: { loader: async () => PhoenixSignInPage },
    }),
  ],
});
