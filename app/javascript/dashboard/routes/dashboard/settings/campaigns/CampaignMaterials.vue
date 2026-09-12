<script>
import { DirectUpload } from 'activestorage';
import { useAlert } from 'dashboard/composables';

export default {
  props: {
    value: {
      type: Array,
      default: () => [],
    },
  },
  data() {
    return {
      isUploading: false,
    };
  },
  methods: {
    async onFilesSelected(event) {
      const files = Array.from(event.target.files || []);
      if (!files.length) return;

      this.isUploading = true;
      try {
        const uploaded = [];
        for (const file of files) {
          // Preserve the original file exactly as selected. Campaign materials
          // intentionally do not restrict MIME type; each channel may still
          // reject a type/size it cannot transport.
          // eslint-disable-next-line no-await-in-loop
          uploaded.push(await this.uploadFile(file));
        }
        this.$emit('input', [...this.value, ...uploaded]);
      } catch (error) {
        useAlert('Não foi possível enviar um dos materiais da campanha.');
      } finally {
        this.isUploading = false;
        event.target.value = '';
      }
    },
    uploadFile(file) {
      return new Promise((resolve, reject) => {
        const upload = new DirectUpload(
          file,
          '/rails/active_storage/direct_uploads'
        );
        upload.create((error, blob) => {
          if (error) {
            reject(error);
            return;
          }
          resolve({
            signed_id: blob.signed_id,
            filename: blob.filename || file.name,
            content_type: blob.content_type || file.type,
            byte_size: blob.byte_size || file.size,
          });
        });
      });
    },
    removeMaterial(index) {
      this.$emit(
        'input',
        this.value.filter((material, materialIndex) => materialIndex !== index)
      );
    },
    formatBytes(value) {
      const bytes = Number(value || 0);
      if (bytes < 1024) return `${bytes} B`;
      if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
      if (bytes < 1024 * 1024 * 1024) {
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
      }
      return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
    },
  },
};
</script>

<template>
  <div class="campaign-materials">
    <label>
      Materiais da campanha
      <input type="file" multiple :disabled="isUploading" @change="onFilesSelected" />
    </label>
    <p class="campaign-materials__help">
      Anexe HTML, imagens, PDF, documentos, planilhas, ZIP ou qualquer outro arquivo necessário. O arquivo será enviado como material da mensagem quando o canal suportar esse conteúdo.
    </p>
    <p v-if="isUploading" class="campaign-materials__help">
      Enviando material…
    </p>
    <ul v-if="value.length" class="campaign-materials__list">
      <li v-for="(material, index) in value" :key="material.signed_id || material.id || index">
        <div>
          <strong>{{ material.filename }}</strong>
          <span>
            {{ material.content_type || 'arquivo' }} · {{ formatBytes(material.byte_size) }}
          </span>
        </div>
        <button type="button" class="button clear" @click="removeMaterial(index)">
          Remover
        </button>
      </li>
    </ul>
  </div>
</template>

<style lang="scss" scoped>
.campaign-materials {
  @apply mb-4;

  &__help {
    @apply mt-1 mb-2 text-xs text-slate-500;
  }

  &__list {
    @apply mt-2 p-0 list-none;

    li {
      @apply flex items-center justify-between gap-3 py-2 border-b border-slate-100;
    }

    span {
      @apply block text-xs text-slate-500;
    }
  }
}
</style>
