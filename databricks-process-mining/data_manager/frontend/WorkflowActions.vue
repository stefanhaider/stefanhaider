<!-- Zeigt genau die Aktionen, die die Status-Maschine des Backends aktuell erlaubt. -->
<script setup lang="ts">
import { onMounted, toRef, watch } from "vue";
import { useWorkflow } from "./useWorkflow";

const props = defineProps<{ process: string; caseId: string | null }>();
const emit = defineEmits<{ (e: "changed", to: string): void }>();
const { allowed, loading, rejection, load, transition } = useWorkflow(props.process, toRef(props, "caseId"));

onMounted(load);
watch(() => props.caseId, load);

async function run(to: string) {
  if (await transition(to)) emit("changed", to);
}
</script>

<template>
  <div class="workflow-actions">
    <button v-for="a in allowed" :key="a.to" :disabled="loading" :title="a.note" @click="run(a.to)">
      {{ a.to }}
    </button>
    <p v-if="!loading && allowed.length === 0">Keine weiteren Schritte möglich.</p>
    <p v-if="rejection" role="alert">{{ rejection }}</p>
  </div>
</template>
