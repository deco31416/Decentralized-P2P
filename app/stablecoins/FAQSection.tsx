import { Card, CardContent, CardHeader, CardTitle } from '@/app/components/ui/card'
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/app/components/ui/accordion'

export function FAQSection({ name }: { name: string }) {
  const questions = [
    {
      question: `¿Cuál es el precio actual de ${name}?`,
      answer: "El precio actual se muestra en tiempo real en la sección superior de esta página.",
    },
    {
      question: `¿Cuál es la capitalización de mercado de ${name}?`,
      answer: "La capitalización de mercado varía según el suministro en circulación y el precio actual.",
    },
    {
      question: `¿Cómo comprar ${name}?`,
      answer: "Puedes comprar en exchanges regulados que listen la moneda.",
    },
  ]

  return (
    <Card>
      <CardHeader>
        <CardTitle>Preguntas frecuentes</CardTitle>
      </CardHeader>
      <CardContent>
        <Accordion type="single" collapsible>
          {questions.map((q, i) => (
            <AccordionItem key={i} value={`item-${i}`}>
              <AccordionTrigger>{q.question}</AccordionTrigger>
              <AccordionContent>{q.answer}</AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </CardContent>
    </Card>
  )
}

