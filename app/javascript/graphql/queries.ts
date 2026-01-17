import { gql } from '@apollo/client'

export const GET_PUBLIC_PUBLISHED_PROJECTS = gql`
  query GetPublicPublishedProjects {
    publicPublishedProjects {
      id
      name
      slug
      status
      promptType
      createdAt
      updatedAt
    }
  }
`

export const CREATE_QUERY = gql`
  mutation CreateQuery($input: CreateQueryInput!) {
    createQuery(input: $input) {
      query {
        id
        query
        response
        answer
        projectId
        createdAt
      }
      errors
    }
  }
`
