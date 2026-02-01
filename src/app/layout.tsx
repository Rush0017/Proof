import './globals.css'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Proof - Bitcoin Professional Network',
  description: 'Find work. Get paid in sats.',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
