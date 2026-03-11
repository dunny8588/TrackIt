<template>
  <div class="q-v-date-range-picker" style="min-width: 180px">
    <q-btn :color="theme.bgColor" flat dense @click="prevHandler" icon="mdi-chevron-left">
      <q-tooltip>Previous time range</q-tooltip>
    </q-btn>
    <q-btn @click="dateRangeToggle" flat :color="theme.bgColor" style="min-width: 124px; font-size: .8rem; line-height: .8rem;" class="q-pa-none date-display">
      <div>
        <div>{{displayStartDate}}</div>
        <div v-if="!isWeekOrMonthMode" style="font-size: .5rem">|</div>
        <div v-if="!isWeekOrMonthMode">{{formatDate(dateModel[1])}}</div>
      </div>
      <q-tooltip>Change time</q-tooltip>
    </q-btn>
    <q-btn :color="theme.bgColor" flat dense @click="nextHandler" icon="mdi-chevron-right">
      <q-tooltip>Next time range</q-tooltip>
    </q-btn>
    <q-dialog ref="dateRangePickerModal" content-class="modal-date-range">
      <q-card>
        <q-card-section class="scroll q-pa-none" :class="{[`bg-${theme.bgColor}`]: true, 'text-white': !!theme.bgColor}">
          <div class="flex flex-center" style="max-width: 330px;">
            <div class="fit text-center q-my-sm">
              <q-btn-toggle 
                v-model="mode" 
                :options="dateRangeModeOptions" 
                :color="theme.bgColor" 
                text-color="grey" 
                :toggle-text-color="theme.color" 
                flat
              >
                <q-tooltip v-if="mode === 0">Select a single day</q-tooltip>
                <q-tooltip v-if="mode === 1">Select an entire week</q-tooltip>
                <q-tooltip v-if="mode === 2">Select an entire month</q-tooltip>
                <q-tooltip v-if="mode === 3">Select a custom date range</q-tooltip>
              </q-btn-toggle>
            </div>
            <date-range-picker
              class="q-ma-sm"
              v-model="dateModel"
              :mode="mode"
              :theme="theme"
              @change:mode="changeModeDateTimeRangeHandler"
              @error="flag => saveDisabled = flag"
            />
          </div>
        </q-card-section>
        <q-card-actions align='between' :class="{[`bg-${theme.bgColor}`]: true, 'text-white': !!theme.bgColor}">
          <q-btn flat :color="theme.color" dense icon="mdi-map-clock-outline" @click="$emit('reinit'),dateRangeModalClose()">
            <q-tooltip>Reinit time by devices positions</q-tooltip>
          </q-btn>
          <div>
            <q-btn flat :color="theme.color" @click="dateRangeModalClose">close</q-btn>
            <q-btn flat :color="theme.color" @click="dateRangeModalSave" :disable="saveDisabled">save</q-btn>
          </div>
        </q-card-actions>
      </q-card>
    </q-dialog>
  </div>
</template>

<script>
import { date } from 'quasar'
import DateRangePicker from 'datetimerangepicker'
export default {
  props: ['theme', 'date'],
  data () {
    return {
      dateModel: this.date,
      mode: 0,
      saveDisabled: false,
      dateRangeModeOptions: [
        { label: 'Day', value: 0 },
        { label: 'Week', value: 1 },
        { label: 'Month', value: 2 },
        { label: 'Range', value: 3 }
      ]
    }
  },
  computed: {
    isWeekOrMonthMode() {
      return this.mode === 1 || this.mode === 2;
    },
    displayStartDate() {
      if (this.mode === 1) { // Week
        const weekDate = new Date(this.dateModel[0]);
        const weekNumber = this.getWeekNumber(weekDate);
        return `Week ${weekNumber}, ${date.formatDate(this.dateModel[0], 'YYYY')}`;
      } 
      else if (this.mode === 2) { // Month
        return date.formatDate(this.dateModel[0], 'MMMM YYYY');
      }
      else {
        return this.formatDate(this.dateModel[0]);
      }
    }
  },
  methods: {
    dateRangeToggle () {
      this.$refs.dateRangePickerModal.toggle()
    },
    dateRangeModalClose () {
      this.$refs.dateRangePickerModal.hide()
    },
    changeModeDateTimeRangeHandler (mode) {
      this.mode = mode
    },
    dateRangeModalSave () {
      let [from, to] = this.dateModel
      to += 999 // ms
      this.$emit('save', [from ,to])
      this.dateRangeModalClose()
    },
    formatDate (timestamp) {
      // Check if we're viewing a week or month - show a more compact format
      if (this.mode === 1) { // Week
        // For week mode, show "Week X, YYYY" for the beginning date
        const weekDate = new Date(timestamp);
        const weekNumber = this.getWeekNumber(weekDate);
        
        if (this.isStartDate(timestamp)) {
          return `Week ${weekNumber}, ${date.formatDate(timestamp, 'YYYY')}`;
        }
      } 
      else if (this.mode === 2) { // Month
        // For month mode, show "Month YYYY" for the beginning date
        if (this.isStartDate(timestamp)) {
          return date.formatDate(timestamp, 'MMMM YYYY');
        }
      }
      
      // Default format for all other modes
      return date.formatDate(timestamp, 'DD/MM/YYYY HH:mm:ss');
    },
    
    isStartDate(timestamp) {
      // Check if this timestamp is the start date in the date model
      return Math.abs(timestamp - this.dateModel[0]) < 1000; // Within 1 second
    },
    
    getWeekNumber(date) {
      // Get the ISO week number
      const d = new Date(date);
      d.setHours(0, 0, 0, 0);
      d.setDate(d.getDate() + 3 - (d.getDay() + 6) % 7);
      const week1 = new Date(d.getFullYear(), 0, 4);
      return 1 + Math.round(((d.getTime() - week1.getTime()) / 86400000 - 3 + (week1.getDay() + 6) % 7) / 7);
    },
    prevHandler () {
      const delta = Math.floor(this.dateModel[1]) - Math.floor(this.dateModel[0]),
        newTo = Math.floor(this.dateModel[0]) - 1, // ms
        newFrom = newTo - delta
      this.dateModel = [newFrom, newTo]
      this.$emit('save', this.dateModel)
    },
    nextHandler () {
      const delta = Math.floor(this.dateModel[1]) - Math.floor(this.dateModel[0]),
        newFrom = Math.floor(this.dateModel[1]) + 1, // ms
        newTo = newFrom + delta
      this.dateModel = [newFrom, newTo]
      this.$emit('save', this.dateModel)
    }
  },
  watch: {
    date (date) {
      this.dateModel = date
    }
  },
  components: { DateRangePicker }
}
</script>

<style lang="stylus">
  .q-v-date-range-picker
    .q-btn__wrapper
      padding-left 0
      padding-right 0
    
    .q-btn-toggle
      .q-btn
        min-width: 60px
        padding: 0 8px
        
    .q-btn.date-display
      min-height: 54px
  
  .modal-date-range
    .q-dialog__inner--minimized
      padding 6px
      
    .q-btn-toggle
      margin-bottom: 10px
</style>
