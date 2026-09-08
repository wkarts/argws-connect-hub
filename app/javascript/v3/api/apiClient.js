import axios from 'axios';

const { apiHost = '' } = window.hubConfig || {};
const hubAPI = axios.create({ baseURL: `${apiHost}/` });

export default hubAPI;
