import { createBackendModule } from '@backstage/backend-plugin-api';
import {
  defaultGroupTransformer,
  defaultUserTransformer,
  microsoftGraphOrgEntityProviderTransformExtensionPoint,
} from '@backstage/plugin-catalog-backend-module-msgraph';

// Entity names end up in AWS resource names (requester, group), so they must
// match the infrastructure identifier rule ^[a-z][a-z0-9]*(-[a-z0-9]+)*$.
// Users: mailNickname (jdoe). Groups: displayName minus "phoenix-" (vision).
export function toIdentifier(value: string): string | undefined {
  const id = value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^[^a-z]+|-+$/g, '');
  return id || undefined;
}

export default createBackendModule({
  pluginId: 'catalog',
  moduleId: 'phoenix-entra-naming',
  register(env) {
    env.registerInit({
      deps: {
        transformers: microsoftGraphOrgEntityProviderTransformExtensionPoint,
      },
      async init({ transformers }) {
        transformers.setUserTransformer(async (user, photo) => {
          const entity = await defaultUserTransformer(user, photo);
          const name = user.mailNickname && toIdentifier(user.mailNickname);
          if (!entity || !name) return undefined; // no usable id: not ingested
          entity.metadata.name = name;
          return entity;
        });
        transformers.setGroupTransformer(async (group, photo) => {
          const entity = await defaultGroupTransformer(group, photo);
          const name =
            group.displayName &&
            toIdentifier(group.displayName.replace(/^phoenix-/i, ''));
          if (!entity || !name) return undefined;
          entity.metadata.name = name;
          return entity;
        });
      },
    });
  },
});
