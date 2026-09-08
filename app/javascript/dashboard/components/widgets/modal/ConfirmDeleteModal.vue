<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import Modal from '../../Modal.vue';
export default {
  components: {
    Modal,
  },

  props: {
    show: {
      type: Boolean,
      default: false,
    },
    title: {
      type: String,
      default: '',
    },
    message: {
      type: String,
      default: '',
    },
    confirmText: {
      type: String,
      default: '',
    },
    rejectText: {
      type: String,
      default: '',
    },
    confirmValue: {
      type: String,
      default: '',
    },
    confirmPlaceHolderText: {
      type: String,
      default: '',
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      value: '',
    };
  },
  validations: {
    value: {
      required,
      isEqual(value) {
        return value === this.confirmValue;
      },
    },
  },
  methods: {
    closeModal() {
      this.value = '';
      this.$emit('onClose');
    },
    onConfirm() {
      this.$emit('onConfirm');
    },
  },
};
</script>

<!-- eslint-disable vue/no-mutating-props -->
<template>
  <Modal :show.sync="show" :on-close="closeModal">
    <hub-modal-header :header-title="title" :header-content="message" />
    <form @submit.prevent="onConfirm">
      <hub-input
        v-model="value"
        type="text"
        :class="{ error: v$.value.$error }"
        :placeholder="confirmPlaceHolderText"
        @blur="v$.value.$touch"
      />
      <div class="button-wrapper">
        <hub-button color-scheme="alert" :is-disabled="v$.value.$invalid">
          {{ confirmText }}
        </hub-button>
        <hub-button class="clear" @click.prevent="closeModal">
          {{ rejectText }}
        </hub-button>
      </div>
    </form>
  </Modal>
</template>
