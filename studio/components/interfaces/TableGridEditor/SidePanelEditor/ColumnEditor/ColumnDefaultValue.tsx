import React, { FC } from 'react'
import { isNil } from 'lodash'
import { Select } from '@supabase/ui'
import { PostgresType } from '@supabase/postgres-meta'

import InputWithSuggestions from './InputWithSuggestions'
import { POSTGRES_DATA_TYPES } from '../SidePanelEditor.constants'
import { ColumnField } from '../SidePanelEditor.types'
import { Suggestion } from './ColumnEditor.types'
import { getSelectedEnumValues } from './ColumnEditor.utils'
import { typeExpressionSuggestions } from './ColumnEditor.constants'

interface Props {
  columnFields: ColumnField
  enumTypes: PostgresType[]
  onUpdateField: (changes: Partial<ColumnField>) => void
}

const ColumnDefaultValue: FC<Props> = ({
  columnFields,
  enumTypes = [],
  onUpdateField = () => {},
}) => {
  const suggestions: Suggestion[] = typeExpressionSuggestions?.[columnFields.format] ?? []

  // If selected column type is a user-defined enum, show a dropdown list of options
  const isUserDefinedEnum: boolean =
    isNil(columnFields.format) && !POSTGRES_DATA_TYPES.includes(columnFields.format)

  if (isUserDefinedEnum) {
    const enumValues = getSelectedEnumValues(columnFields.format, enumTypes)
    return (
      <Select
        label="Default Value"
        layout="horizontal"
        value={columnFields.defaultValue}
        onChange={(event: any) => onUpdateField({ defaultValue: event.target.value })}
      >
        <Select.Option key="empty-enum" value="">
          ---
        </Select.Option>
        {enumValues.map((value: string) => (
          <Select.Option key={value} value={value}>
            {value}
          </Select.Option>
        ))}
      </Select>
    )
  }

  return (
    <InputWithSuggestions
      label="Default Value"
      layout="horizontal"
      description="Can either be a literal or an expression (e.g uuid_generate_v4())"
      placeholder="NULL"
      value={columnFields?.defaultValue ?? ''}
      format={columnFields?.format}
      suggestionsHeader="Suggested expressions"
      suggestions={suggestions}
      onChange={(event: any) => onUpdateField({ defaultValue: event.target.value })}
      onSelectSuggestion={(suggestion: Suggestion) =>
        onUpdateField({ defaultValue: suggestion.name })
      }
    />
  )
}

export default ColumnDefaultValue
