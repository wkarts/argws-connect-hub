import VueRouter from 'vue-router';

import routes from './routes';
import { validateRouteAccess } from '../helpers/RouteHelper';

export const router = new VueRouter({ mode: 'history', routes });

export const initalizeRouter = () => {
  router.beforeEach((to, _, next) => {

    return validateRouteAccess(to, next, window.hubConfig);
  });
};

export default router;
