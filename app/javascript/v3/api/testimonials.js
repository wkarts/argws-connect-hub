import hubConstants from 'dashboard/constants/globals';
import hubAPI from './apiClient';

export const getTestimonialContent = () => {
  return hubAPI.get(hubConstants.TESTIMONIAL_URL);
};
