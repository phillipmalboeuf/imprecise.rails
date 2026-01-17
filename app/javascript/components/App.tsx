import { FC } from 'react'
import { ApolloProvider } from './ApolloProvider'
import Queries from './Queries'

const App: FC = () => {
  return (
    <ApolloProvider>
      <Queries />
    </ApolloProvider>
  )
}

export default App
