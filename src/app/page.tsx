import Link from 'next/link'

export default function Home() {
  return (
    <main className="min-h-screen bg-gradient-to-b from-orange-50 to-white">
      <header className="p-6 flex justify-between items-center max-w-6xl mx-auto">
        <div className="flex items-center gap-2">
          <span className="text-2xl">⚡</span>
          <span className="font-bold text-xl">Proof</span>
        </div>
        <nav className="flex gap-4">
          <Link href="/jobs" className="hover:text-orange-600">Jobs</Link>
          <Link href="/dashboard" className="bg-orange-500 text-white px-4 py-2 rounded-lg hover:bg-orange-600">
            Dashboard
          </Link>
        </nav>
      </header>

      <section className="max-w-4xl mx-auto text-center py-20 px-6">
        <h1 className="text-5xl font-bold mb-6">
          Work for <span className="text-orange-500">Bitcoin</span>
        </h1>
        <p className="text-xl text-gray-600 mb-8">
          The professional network where reputation is portable and payments are instant.
        </p>
        <div className="flex gap-4 justify-center">
          <Link href="/jobs" className="bg-orange-500 text-white px-8 py-3 rounded-lg text-lg hover:bg-orange-600">
            Find Work
          </Link>
          <Link href="/jobs/new" className="border border-gray-300 px-8 py-3 rounded-lg text-lg hover:border-orange-500">
            Post a Job
          </Link>
        </div>
      </section>

      <footer className="text-center py-8 text-gray-500">
        <p>Built on Bitcoin, Nostr & Lightning ⚡</p>
      </footer>
    </main>
  )
}
