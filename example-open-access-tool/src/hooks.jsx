import { useEffect, useState } from "react";
import { getServiceApiUrl, supabase } from "./auth";

export function useSupabaseSession() {
  const [session, setSession] = useState(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
    });

    return () => subscription.unsubscribe();
  }, []);

  return session;
}

export function useWhoami(session) {
  const [whoami, setWhoami] = useState(null);
  const [error, setError] = useState(null);
  const [fullName, setFullName] = useState(null);
  const [roles, setRoles] = useState(null);

  useEffect(() => {
    if (!session?.access_token) {
      setWhoami(null);
      return;
    }

    const apiUrl = getServiceApiUrl();

    fetch(`${apiUrl}/whoami`, {
      headers: {
        Authorization: `Bearer ${session.access_token}`,
      },
    })
      .then(async (response) => {
        const data = await response.json();
        return response.ok ? data : Promise.reject(data);
      })
      .then((data) => {
        setWhoami(data);
        setFullName(data?.user?.user?.user_metadata?.full_name);
        setRoles(data?.keycloak_roles);
        setError(null);
      })
      .catch((err) => {
        console.error("Error fetching whoami:", err);
        setError(err);
        setWhoami(null);
        setFullName(null);
        setRoles(null);
      });
  }, [session?.access_token]);

  return { whoami, error, fullName, roles };
}
