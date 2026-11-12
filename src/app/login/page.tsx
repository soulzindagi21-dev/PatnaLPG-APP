"use client";

import { useActionState } from "react";
import { login, type LoginState } from "./actions";

export default function LoginPage() {
  const [state, action, pending] = useActionState<LoginState, FormData>(login, {});

  return (
    <main className="flex min-h-screen items-center justify-center bg-neutral-50 px-4">
      <form
        action={action}
        className="w-full max-w-sm space-y-4 rounded-xl border border-neutral-200 bg-white p-6 shadow-sm"
      >
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Patna LPG</h1>
          <p className="text-sm text-neutral-500">Sign in with your mobile number</p>
        </div>

        <label className="block text-sm font-medium text-neutral-700">
          Mobile number
          <input
            name="mobile"
            type="tel"
            inputMode="numeric"
            autoComplete="username"
            maxLength={10}
            required
            className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-base"
          />
        </label>

        <label className="block text-sm font-medium text-neutral-700">
          Password
          <input
            name="password"
            type="password"
            autoComplete="current-password"
            required
            className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-base"
          />
        </label>

        {state.error && (
          <p role="alert" className="text-sm text-red-600">
            {state.error}
          </p>
        )}

        <button
          type="submit"
          disabled={pending}
          className="w-full rounded-lg bg-orange-600 px-3 py-2 font-medium text-white disabled:opacity-60"
        >
          {pending ? "Signing in..." : "Sign in"}
        </button>
      </form>
    </main>
  );
}
