export const useInstallationName = (str, installationName) => {
  if (str && installationName) {
    return str.replace(/Hub/g, installationName);
  }
  return str;
};

export default {
  methods: {
    useInstallationName,
  },
};
