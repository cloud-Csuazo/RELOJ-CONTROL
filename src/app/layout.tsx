import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: { default: 'Nexo Laboral', template: '%s · Nexo Laboral' }, description: 'Plataforma privada multiempresa para equipos y administración.', robots: { index: false, follow: false } };
export default function RootLayout({ children }: Readonly<{children: React.ReactNode}>) { return <html lang="es-CL"><body>{children}</body></html>; }
