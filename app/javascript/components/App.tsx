import { FC } from 'react'

const App: FC = () => {
  return (
    <div className="hero bg-base-200">
      <div className="hero-content py-8 text-center">
        <div className="max-w-md">
          <h1 className="text-6xl" style={{ fontSize: "6vw" }}>
            <em>Imprecise</em><br />
            Analysis
          </h1>
          <p className="text-lg py-2 mb-4">
            Analyze texts with AI.
          </p>
          <a href="/projects" className="btn btn-primary">Get Started</a>
        </div>
      </div>
    </div>
  )
}

export default App
