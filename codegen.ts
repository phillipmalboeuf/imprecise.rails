import type { CodegenConfig } from '@graphql-codegen/cli'

const config: CodegenConfig = {
  schema: {
    'http://localhost:3000/graphql/introspect': {
      method: 'GET',
    },
  },
  documents: ['app/javascript/**/*.{ts,tsx}'],
  generates: {
    'app/javascript/graphql/generated.ts': {
      plugins: [
        'typescript',
        'typescript-operations',
        'typescript-react-apollo',
      ],
      config: {
        withHooks: true,
        withComponent: false,
        withHOC: false,
        skipTypename: false,
      },
    },
  },
}

export default config
