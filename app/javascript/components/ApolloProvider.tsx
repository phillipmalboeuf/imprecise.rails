import { FC, ReactNode } from 'react'
import { ApolloProvider as Provider } from '@apollo/client/react'
import { apolloClient } from '../apollo-client'

interface ApolloProviderProps {
  children: ReactNode
}

export const ApolloProvider: FC<ApolloProviderProps> = ({ children }) => {
  return <Provider client={apolloClient}>{children}</Provider>
}
