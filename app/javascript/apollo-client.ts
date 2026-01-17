import { ApolloClient, InMemoryCache, createHttpLink, from } from '@apollo/client'
import { setContext } from '@apollo/client/link/context'

const httpLink = createHttpLink({
  uri: '/graphql',
  credentials: 'same-origin',
})

const authLink = setContext((_, { headers }) => {
  // Get CSRF token
  const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
  
  // Merge with any headers from context (e.g., Authorization header from mutations)
  return {
    headers: {
      ...headers,
      'X-CSRF-Token': csrfToken || '',
    },
  }
})

export const apolloClient = new ApolloClient({
  link: from([authLink, httpLink]),
  cache: new InMemoryCache(),
})
