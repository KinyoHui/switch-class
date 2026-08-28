<script setup>
defineProps({ notice: { type: Object, default: null } })
defineEmits(['close'])
</script>

<template>
  <Transition
    enter-active-class="transition duration-150" leave-active-class="transition duration-150"
    enter-from-class="opacity-0 -translate-y-1" leave-to-class="opacity-0 -translate-y-1"
  >
    <div v-if="notice" class="fixed inset-x-0 top-3 z-50 flex justify-center px-3">
      <div
        class="flex max-w-lg items-start gap-3 rounded-lg border px-4 py-2.5 text-sm shadow-lg backdrop-blur"
        :class="notice.type === 'error'
          ? 'border-rose-800 bg-rose-950/90 text-rose-200'
          : 'border-cyan-800 bg-cyan-950/90 text-cyan-100'"
      >
        <span class="whitespace-pre-line">{{ notice.text }}</span>
        <button class="shrink-0 opacity-60 hover:opacity-100" @click="$emit('close')">✕</button>
      </div>
    </div>
  </Transition>
</template>
