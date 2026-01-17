import { FC, useState, useEffect, FormEvent, Fragment } from 'react'
import { useQuery, useMutation } from '@apollo/client/react'
import { GET_PUBLIC_PUBLISHED_PROJECTS, CREATE_QUERY } from '../graphql/queries'
import type {
  GetPublicPublishedProjectsQuery,
  CreateQueryPayload,
  CreateQueryInput,
} from '../graphql/generated'


interface QueryFormProps {
  projectId: string
  promptType: string
}

const QueryForm: FC<QueryFormProps> = ({ projectId, promptType }) => {
  const [queryText, setQueryText] = useState('')
  const [response, setResponse] = useState<any>(null)
  const [errors, setErrors] = useState<string[]>([])

  const [createQuery, { loading }] = useMutation<
    { createQuery?: CreateQueryPayload },
    { input: CreateQueryInput }
  >(CREATE_QUERY, {
    context: {
    },
    onCompleted: (data) => {
      if (data?.createQuery?.errors?.length) {
        setErrors(data.createQuery.errors)
      } else if (data?.createQuery?.query) {
        setResponse(data.createQuery.query)
        setQueryText('')
        setErrors([])
      }
    },
    onError: (err) => {
      setErrors([err.message || 'An error occurred while creating the query'])
      setResponse(null)
    },
  })

  const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault()

    setErrors([])
    setResponse(null)

    await createQuery({
      variables: {
        input: {
          projectId,
          query: queryText.trim(),
        },
      },
    })
  }

  return (
    <div className="space-y-4 max-w-md">
      <form onSubmit={handleSubmit} className="space-y-4 max-w-md">
        <div>
          <label htmlFor={`query-text-${projectId}`} className="floating-label">
            <span className="label-text">Query</span>
          
            <textarea
              id={`query-text-${projectId}`}
              className="textarea textarea-ghost w-full"
              rows={6}
              value={queryText}
              onChange={(e) => setQueryText(e.target.value)}
              placeholder={`Enter your ${{
                'IS_IT_SPAM': 'spam',
                'IS_IT_AI': 'AI',
                'TOPICS': 'topics',
                'SENTIMENT': 'sentiment',
              }[promptType]} query here...`}
              disabled={loading}
            />
          </label>
        </div>
        <button
          type="submit"
          className="btn btn-primary"
          disabled={loading || !queryText.trim()}
        >
          {loading ? (
            <>
              <span className="loading loading-spinner loading-sm"></span>
              Sending...
            </>
          ) : (
            'Submit Query'
          )}
        </button>
      </form>

      {errors.length > 0 && (
        <div className="alert alert-error">
          <div>
            <h3 className="font-bold">Error</h3>
            <ul className="list-disc list-inside">
              {errors.map((error, index) => (
                <li key={index}>{error}</li>
              ))}
            </ul>
          </div>
        </div>
      )}

      {response && (
        <div className="space-y-2">
          <div className="mb-4">
            <h4 className="font-semibold mb-1">Answer</h4>
            <div className="flex flex-wrap gap-1">
              {response.answer.map((term: string) => (
                <span className="badge badge-primary">{term}</span>
              ))}
            </div>
          </div>

          <details className="dropdown">
            <summary className="btn btn-sm btn-soft m-1">View Response</summary>
            <div className="bg-base-200 p-4 rounded">
              <pre className="whitespace-pre-wrap text-sm">
                {JSON.stringify(response.response || response, null, 2)}
              </pre>
            </div>
          </details>
        </div>
      )}
    </div>
  )
}

const Queries: FC = () => {
  const { data, loading, error } = useQuery<GetPublicPublishedProjectsQuery>(
    GET_PUBLIC_PUBLISHED_PROJECTS
  )
  
  const [selectedTab, setSelectedTab] = useState<string | null>(null)

  // Update selectedTab when data loads
  useEffect(() => {
    if (data?.publicPublishedProjects?.[0]?.id && !selectedTab) {
      setSelectedTab(data.publicPublishedProjects[0].id)
    }
  }, [data, selectedTab])

  if (loading) {
    return (
      <div className="p-6 flex flex-col items-center justify-center">
        <span className="loading loading-spinner loading-lg"></span>
        <p className="mt-4">Loading projects...</p>
      </div>
    )
  }

  if (error) {
    return (
      <div className="p-6">
        <div className="alert alert-error">
          <span>Error: {error.message}</span>
        </div>
      </div>
    )
  }

  if (!data?.publicPublishedProjects || data.publicPublishedProjects.length === 0) {
    return (
      <div className="p-6">
        <div className="alert alert-info">
          <span>No published projects found.</span>
        </div>
      </div>
    )
  }

  const projects = data.publicPublishedProjects

  return (
    <div className="p-6 py-12 flex justify-center">
      <div className="tabs tabs-lift max-w-md mx-auto">
        {projects.map((project) => (
          <Fragment key={project.id}>
            <label className="tab">
              <input
                type="radio"
                name="project_tabs"
                checked={selectedTab === project.id}
                onChange={() => setSelectedTab(project.id)}
              />
              {project.name}
            </label>
            <div
              className={`tab-content bg-base-100 border-base-300 p-6 ${selectedTab === project.id ? '' : 'hidden'}`}
            >
              <div className="space-y-4">
                <QueryForm projectId={project.id} promptType={project.promptType} />
              </div>
            </div>
          </Fragment>
        ))}
      </div>
    </div>
  )
}

export default Queries